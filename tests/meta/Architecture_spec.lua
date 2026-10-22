local Fs = require("helpers.fs")
local Loader = require("helpers.loader")

---@param path string
---@return fun(): integer, string
local function CodeLines(path)
    local number = 0
    local lines = Fs.ReadFile(path):gmatch("([^\n]*)\n?")
    return function()
        local line = lines()
        if line == nil then
            return nil
        end
        number = number + 1
        return number, (line:gsub("%-%-.*$", ""))
    end
end

local function IsUiFile(path)
    return path:find("^ui/") ~= nil or path:find("/ui/") ~= nil or path:find("UI%.lua$") ~= nil
end

---"TwinFangs" -> "twin_fangs"
local function SnakeCase(name)
    return (name:gsub("(%l)(%u)", "%1_%2"):lower())
end

describe("Architecture", function()
    local files = Loader.ReadLuaFiles()

    it("creates frames and tooltips only in UI files and api/", function()
        for _, path in ipairs(files) do
            if not IsUiFile(path) and not path:find("^api/") then
                for number, line in CodeLines(path) do
                    assert(
                        not line:find("%f[%w_]CreateFrame%f[^%w_]") and not line:find("%f[%w_]GameTooltip%f[^%w_]"),
                        path .. ":" .. number .. " builds UI outside a UI file"
                    )
                end
            end
        end
    end)

    it("keeps feature internals off the shared namespace", function()
        for _, path in ipairs(files) do
            if path:find("^modules/[^/]+/") then
                for number, line in CodeLines(path) do
                    assert(
                        not line:find("^ns%.[%w_]+%s*=[^=]"),
                        path .. ":" .. number .. " adds a feature table to ns; use ns.Modules.Internals"
                    )
                end
            end
        end
    end)

    it("lets a feature reach only its own internals", function()
        for _, path in ipairs(files) do
            local feature = path:match("^modules/[^/]+/([^/]+)/")
            for number, line in CodeLines(path) do
                for name in line:gmatch('Modules%.Internals%(%s*"([^"]+)"') do
                    assert(
                        feature and SnakeCase(name) == feature,
                        path .. ":" .. number .. " reaches internals of " .. name
                    )
                end
            end
        end
    end)
end)

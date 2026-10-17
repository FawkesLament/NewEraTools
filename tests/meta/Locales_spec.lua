local Fs = require("helpers.fs")
local Loader = require("helpers.loader")

local BASE_LOCALE_PATH = "locales/zhCN.lua"

local function CollectKeys(source, pattern, keys)
    for key in source:gmatch(pattern) do
        keys[key] = true
    end
end

describe("Locales", function()
    -- The fake client locale is zhCN, so this holds exactly the base locale's keys.
    local L = Loader.Load().L

    it("renders a missing key in brackets", function()
        assert.equals("[NOT_A_KEY]", L.NOT_A_KEY)
    end)

    it("defines every key used in code in the base locale", function()
        for _, path in ipairs(Fs.ListFiles()) do
            if path:find("%.lua$") and not path:find("^tests/") and not path:find("^locales/") then
                local source = Fs.ReadFile(path)
                local used = {}
                CollectKeys(source, "%f[%w_]L%.([%a_][%w_]*)", used)
                CollectKeys(source, '%f[%w_]L%["([^"]+)"%]', used)
                for key in pairs(used) do
                    assert(rawget(L, key) ~= nil, path .. " uses undefined locale key " .. key)
                end
            end
        end
    end)

    it("only translates keys that exist in the base locale", function()
        for _, path in ipairs(Fs.ListFiles()) do
            if path:find("^locales/.+%.lua$") and path ~= BASE_LOCALE_PATH then
                local keys = {}
                CollectKeys(Fs.ReadFile(path), "\nL%.([%a_][%w_]*)%s*=", keys)
                for key in pairs(keys) do
                    assert(rawget(L, key) ~= nil, path .. " translates unknown key " .. key)
                end
            end
        end
    end)
end)

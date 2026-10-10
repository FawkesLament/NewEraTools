-- Runs every tests/**/*_spec.lua file. Usage, from the addon folder: luajit tests/run.lua
-- Specs use a busted-compatible subset: describe, it, before_each, after_each,
-- assert.equals/same/is_true/is_false/is_nil.
package.path = "./tests/?.lua;" .. package.path

local Fs = require("helpers.fs")

local function Format(value)
    if type(value) == "string" then
        return string.format("%q", value)
    elseif type(value) ~= "table" then
        return tostring(value)
    end
    local parts = {}
    for key, item in pairs(value) do
        table.insert(parts, "[" .. Format(key) .. "] = " .. Format(item))
    end
    table.sort(parts)
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function DeepEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not DeepEqual(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Level 3 points the error at the spec line that called the assertion.
local function Check(passed, message)
    if not passed then
        error(message, 3)
    end
end

assert = setmetatable({
    equals = function(expected, actual)
        Check(expected == actual, "expected " .. Format(expected) .. ", got " .. Format(actual))
    end,
    same = function(expected, actual)
        Check(DeepEqual(expected, actual), "expected " .. Format(expected) .. ", got " .. Format(actual))
    end,
    is_true = function(value)
        Check(value == true, "expected true, got " .. Format(value))
    end,
    is_false = function(value)
        Check(value == false, "expected false, got " .. Format(value))
    end,
    is_nil = function(value)
        Check(value == nil, "expected nil, got " .. Format(value))
    end,
}, {
    __call = function(_, value, message, ...)
        if not value then
            error(message or "assertion failed!", 2)
        end
        return value, message, ...
    end,
})

local passed = 0
local failures = {}
local scopes = {}

local function FullName(testName)
    local names = {}
    for _, scope in ipairs(scopes) do
        table.insert(names, scope.name)
    end
    table.insert(names, testName)
    return table.concat(names, " > ")
end

function describe(name, body)
    table.insert(scopes, { name = name })
    body()
    table.remove(scopes)
end

function before_each(callback)
    scopes[#scopes].beforeEach = callback
end

function after_each(callback)
    scopes[#scopes].afterEach = callback
end

local function RunAfterEach()
    for index = #scopes, 1, -1 do
        if scopes[index].afterEach then
            scopes[index].afterEach()
        end
    end
end

function it(name, body)
    local ok, err = pcall(function()
        for _, scope in ipairs(scopes) do
            if scope.beforeEach then
                scope.beforeEach()
            end
        end
        body()
    end)
    local cleanupOk, cleanupErr = pcall(RunAfterEach)
    if ok and not cleanupOk then
        ok, err = false, cleanupErr
    end
    if ok then
        passed = passed + 1
    else
        table.insert(failures, { name = FullName(name), message = tostring(err) })
    end
end

local specs = {}
for _, path in ipairs(Fs.ListFiles()) do
    if path:find("^tests/.+_spec%.lua$") then
        table.insert(specs, path)
    end
end

for _, path in ipairs(specs) do
    local ok, err = pcall(dofile, path)
    if not ok then
        table.insert(failures, { name = path, message = tostring(err) })
        scopes = {}
    end
end

for _, failure in ipairs(failures) do
    print("FAIL " .. failure.name)
    print("     " .. failure.message)
end
print(string.format("%d passed, %d failed (%d spec files)", passed, #failures, #specs))
os.exit(#failures == 0 and 0 or 1)

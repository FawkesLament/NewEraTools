-- Runs every tests/**/*_spec.lua file. Usage, from the addon folder: luajit tests/run.lua
-- Specs use a busted-compatible subset: describe, it, before_each, after_each,
-- assert.equals/same/is_true/is_false/is_nil.
-- describe and it run immediately while the spec file loads. A hook applies only to
-- examples that have not already run. Each describe keeps every before_each and
-- after_each; a later hook does not replace an earlier one.
-- Extra arguments run those files instead of discovery. `--no-discover` runs nothing.
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
local examplesRegistered = 0

local function FullName(testName)
    local names = {}
    for _, scope in ipairs(scopes) do
        table.insert(names, scope.name)
    end
    table.insert(names, testName)
    return table.concat(names, " > ")
end

local function Hooks(scope, key)
    local hooks = scope[key]
    if not hooks then
        hooks = {}
        scope[key] = hooks
    end
    return hooks
end

function describe(name, body)
    table.insert(scopes, { name = name })
    body()
    table.remove(scopes)
end

function before_each(callback)
    table.insert(Hooks(scopes[#scopes], "beforeEach"), callback)
end

function after_each(callback)
    table.insert(Hooks(scopes[#scopes], "afterEach"), callback)
end

local function RunBeforeEach()
    for _, scope in ipairs(scopes) do
        local hooks = scope.beforeEach
        if hooks then
            for _, hook in ipairs(hooks) do
                hook()
            end
        end
    end
end

local function RunAfterEach()
    for index = #scopes, 1, -1 do
        local hooks = scopes[index].afterEach
        if hooks then
            for hookIndex = #hooks, 1, -1 do
                hooks[hookIndex]()
            end
        end
    end
end

function it(name, body)
    examplesRegistered = examplesRegistered + 1
    local ok, err = pcall(function()
        RunBeforeEach()
        body()
    end)
    local cleanupOk, cleanupErr = pcall(RunAfterEach)
    if ok and cleanupOk then
        passed = passed + 1
    end
    if not ok then
        table.insert(failures, { name = FullName(name), message = tostring(err) })
    end
    if not cleanupOk then
        table.insert(failures, { name = FullName(name), message = tostring(cleanupErr) })
    end
end

local function DiscoverSpecs()
    local specs = {}
    for _, path in ipairs(Fs.ListFiles()) do
        if path:find("^tests/.+_spec%.lua$") then
            table.insert(specs, path)
        end
    end
    return specs
end

---Explicit arguments select files. `--no-discover` with no files is an empty run.
---Nil means the caller asked for discovery.
---@return string[]|nil
local function SpecsFromArgs()
    if type(arg) ~= "table" then
        return nil
    end
    local specs = {}
    local explicit = false
    for index = 1, #arg do
        explicit = true
        if arg[index] ~= "--no-discover" then
            table.insert(specs, arg[index])
        end
    end
    if not explicit then
        return nil
    end
    return specs
end

local specs = SpecsFromArgs()
if not specs then
    specs = DiscoverSpecs()
end

if #specs == 0 then
    table.insert(failures, { name = "tests/run.lua", message = "no spec files discovered" })
end

for _, path in ipairs(specs) do
    local registeredBefore = examplesRegistered
    local ok, err = pcall(dofile, path)
    if not ok then
        table.insert(failures, { name = path, message = tostring(err) })
        scopes = {}
    elseif examplesRegistered == registeredBefore then
        table.insert(failures, { name = path, message = "spec file registered no examples" })
    end
end

for _, failure in ipairs(failures) do
    print("FAIL " .. failure.name)
    print("     " .. failure.message)
end
print(string.format("%d passed, %d failed (%d spec files)", passed, #failures, #specs))
os.exit(#failures == 0 and 0 or 1)
